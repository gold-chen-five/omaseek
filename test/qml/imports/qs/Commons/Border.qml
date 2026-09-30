pragma Singleton
import QtQml

QtObject {
  function controlSpec(state, foreground, accent) { return {} }
  function flat(color, width) { return { color: color, width: width } }
}
